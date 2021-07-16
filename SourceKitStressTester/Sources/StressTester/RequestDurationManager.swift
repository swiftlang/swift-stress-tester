//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Common
import Foundation
import TSCBasic

fileprivate extension Array where Element == Int {
  /// Creates a logarithmic histogram. For each `key`, the `value` contains the
  /// number of elements in this array that are smaller than `2 ^ key` but not
  /// smaller than `2 ^ (key - 1)`.
  var logHistogram: [Int: Int] {
    var result: [Int: Int] = [:]
    for value in self {
      let log: Int
      if value == 0 {
        // We put 0 in bucket 0 even though it should be in -inf. But that's
        // too hard to represent and we don't really care about 0 either.
        log = 0
      } else {
        log = Int(log2(Double(value))) + 1
      }
      result[log, default: 0] += 1
    }
    return result
  }
}

/// The time measurement of a single request. The request type and file are 
/// implicitly defined by the structure that this struct is contained in
struct Timing: Codable {
  /// The modification summary describing the state of the source file when the 
  /// request was made.
  var modification: String

  /// The offset in the file at which the request was made.
  var offset: Int

  /// The number of instructions sourcekitd took to exeucte the request.
  var instructions: Int
}

/// Captures aggregated information about executing a certain request kind on a
/// certain file. 
/// Everything except `values` is a legacy data structure used by an analysis
/// script in the source compatibility suite repo and will be removed.
struct AggregatedRequestDurations: Codable {
  static let empty = AggregatedRequestDurations(timings: [])

  /// The log histogram created by the extension on `Array` above.
  var logHistogram: [Int: Int]

  /// The total number of instructions executed by the requests of this type
  /// `totalInstructions` / `requestsExecuted` gives the average number of
  /// instructions per request.
  var totalInstructions: Int

  /// The total number of requests of a given kind executed for a given file
  var requestsExecuted: Int
  
  var values: [Timing]

  init(timings: [Timing]) {
    values = timings
    let instructionCounts = timings.map { $0.instructions }
    logHistogram = instructionCounts.logHistogram
    totalInstructions = instructionCounts.reduce(0, { $0 + $1 })
    requestsExecuted = instructionCounts.count
  }

  mutating func merge(other: AggregatedRequestDurations) {
    self.logHistogram.merge(other.logHistogram, uniquingKeysWith: {
      $0 + $1
    })
    self.totalInstructions += other.totalInstructions
    self.requestsExecuted += other.requestsExecuted
    self.values += other.values
  }
}

/// Contains aggregated information for all request kinds of all files executed
/// by the stress tester.
fileprivate struct RequestDurations: Codable {
  // FIXME: We should be using `RequestKind` as the inner key but that causes
  // the inner dictionary to be serialized as an array (rdar://78099769)
  /// Maps file paths to request kinds to aggregated request duration information
  var files: [String: [String: AggregatedRequestDurations]]
}

/// Collects the durations that requests executed by the stress tester took and
/// writes them to `jsonFile` where the durations are collected together with
/// all other stress tester runs.
/// We are aggregating the results early (just keeping track of total
/// instructions executed for each request type and a logarithmic histogram
/// because keeping track of all request durations would result in a JSON file
/// that is too large to handle easily.
class RequestDurationManager {
  /// The file that stores the request durations and that gets updated as new
  /// aggregated information is added
  let jsonFile: URL

  init(jsonFile: URL) {
    self.jsonFile = jsonFile
  }

  private func getRequestDurations() throws -> RequestDurations {
    guard FileManager.default.fileExists(atPath: jsonFile.path) else {
      return RequestDurations(files: [:])
    }
    let data = try Data(contentsOf: jsonFile)
    return try JSONDecoder().decode(RequestDurations.self, from: data)
  }

  func add(aggregatedDurations: AggregatedRequestDurations, for file: String, requestKind: RequestKind) throws {
    try localFileSystem.withLock(on: AbsolutePath(jsonFile.path), type: .exclusive) {
      var currentTimings = try getRequestDurations()
      currentTimings.files[file, default: [:]][requestKind.rawValue, default: .empty].merge(other: aggregatedDurations)
      let data = try JSONEncoder().encode(currentTimings)
      try data.write(to: jsonFile)
    }
  }
}
