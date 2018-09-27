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

/// Provides convenience APIs for launching and gathering output from a subprocess
class ProcessRunner {
  private static let serialQueue = DispatchQueue(label: "\(ProcessRunner.self)")

  let process: Process
  var launched = false

  init(launchPath: String, arguments: [String], environment: [String: String] = [:]) {
    process = Process()
    process.launchPath = launchPath
    process.arguments = arguments
    process.environment = environment.merging(ProcessInfo.processInfo.environment) { (current, _) in current }
  }

  func run(capturingOutput: Bool = true) -> ProcessResult {
    let out = Pipe(), err = Pipe()
    var outData = Data(), errData = Data()

    if capturingOutput {
      out.fileHandleForReading.readabilityHandler = {outData.append($0.availableData)}
      err.fileHandleForReading.readabilityHandler = {errData.append($0.availableData)}
      process.standardOutput = out
      process.standardError = err
    }

    ProcessRunner.serialQueue.sync {
      process.launch()
      launched = true
    }
    process.waitUntilExit()

    if capturingOutput {
      out.fileHandleForReading.readabilityHandler = nil
      err.fileHandleForReading.readabilityHandler = nil
    }

    return ProcessResult(status: process.terminationStatus, stdout: outData, stderr: errData)
  }

  func terminate() {
    ProcessRunner.serialQueue.sync {
      if launched {
        process.terminate()
      }
    }
  }
}

/// The exit code and output (if redirected) from a subprocess that has terminated
struct ProcessResult {
  let status: Int32
  let stdout: Data
  let stderr: Data
}
