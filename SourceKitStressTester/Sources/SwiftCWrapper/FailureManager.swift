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
struct FailureManager {
  let activeConfig: String
  let expectedFailuresFile: URL
  let resultsFile: URL
  let encoder: JSONEncoder

  /// - parameters:
  ///   - expectedFailuresFile: the URL of a JSON file describing the
  ///   expected failures
  ///   - resultsFile: the URL of the file to use to store failures across
  ///   multiple invocations
  init(activeConfig: String, expectedFailuresFile: URL, resultsFile: URL) {
    self.activeConfig = activeConfig
    self.expectedFailuresFile = expectedFailuresFile
    self.resultsFile = resultsFile
    self.encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
  }

  /// Updates this instance's backing resultsFile to account for the files
  /// processed by this invocation of the wrapper, and the error it detected,
  /// if any.
  ///
  /// - parameters:
  ///   - for: the set of files processed
  ///   - error: the detected error, if any
  func update(for files: Set<String>, error: SourceKitError?) throws -> ExpectedFailure? {
    let failureSpecs = try getFailureSpecifications(applicableTo: files)
    var state = try getCurrentState()
    let matchingSpec = state.add(processedFiles: files, error: error, specs: failureSpecs)
    let data = try encoder.encode(state)
    FileManager.default.createFile(atPath: resultsFile.path, contents: data)
    return matchingSpec
  }

  private func getFailureSpecifications(applicableTo files: Set<String>) throws -> [ExpectedFailure] {
    let data = try Data(contentsOf: expectedFailuresFile)
    return try JSONDecoder().decode([ExpectedFailure].self, from: data)
      .filter { spec in
        spec.applicableConfigs.contains(activeConfig) &&
          files.contains { spec.isApplicable(toPath: $0) }
    }
  }

  private func getCurrentState() throws -> FailureManagerState {
    guard FileManager.default.fileExists(atPath: resultsFile.path) else {
      return FailureManagerState()
    }
    let data = try Data(contentsOf: resultsFile)
    return try JSONDecoder().decode(FailureManagerState.self, from: data)
  }
}

/// Holds the state of the FailureManager that will be serialized across
/// invocations
fileprivate struct FailureManagerState: Codable {
  var processedFiles = Set<String>()
  var expectedFailures = Dictionary<String, [SourceKitError]>()
  var failures = [SourceKitError]()
  var unmatchedExpectedFailures = [ExpectedFailure]()

  /// Updates the state to account for the given set of files covered during
  /// this invocation of the wrapper, and the first error detected, if any.
  ///
  /// - returns: the expected failure that matches the given error, if any
  mutating func add(processedFiles: Set<String>, error: SourceKitError?, specs: [ExpectedFailure]) -> ExpectedFailure? {
    var result: ExpectedFailure? = nil
    let added = processedFiles.subtracting(self.processedFiles)
    unmatchedExpectedFailures.append(contentsOf: specs.filter { spec in
      added.contains {spec.isApplicable(toPath: $0)}
    })
    self.processedFiles.formUnion(processedFiles)
    if let error = error {
      if let match = specs.first(where: {$0.matches(error.request)}) {
        expectedFailures[match.issueUrl] = (expectedFailures[match.issueUrl] ?? []) + [error]
        unmatchedExpectedFailures.removeAll(where: {$0 == match})
        result = match
      } else {
        failures.append(error)
      }
    }
    return result
  }
}

extension DocumentModification {
  /// A String with enough information to unique identify the modified state of
  /// a document in comparison to other modifications produced by the stress
  /// tester.
  var summaryCode: String {
    return "\(mode)-\(content.count)"
  }
}
