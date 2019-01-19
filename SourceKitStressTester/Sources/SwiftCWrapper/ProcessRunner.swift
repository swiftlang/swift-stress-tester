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
    let out = Pipe()
    var outData = Data()

    if capturingOutput {
      process.standardOutput = out
    }
    ProcessRunner.serialQueue.sync {
      process.launch()
      launched = true
    }
    if capturingOutput {
      outData = out.fileHandleForReading.readDataToEndOfFile()
    }
    process.waitUntilExit()

    return ProcessResult(status: process.terminationStatus, stdout: outData)
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
}
