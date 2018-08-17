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

/// The exit code and output (if redirected) from a subprocess that has terminated
struct ProcessResult {
  let status: Int32
  let stdout: String
  let stderr: String
}

/// Provides convenience APIs for launching and gathering output from a subprocess
class ProcessRunner {
  let process: Process
  let redirectOutput: Bool

  init(launchPath: String, arguments: [String], environment: [String: String] = [:], redirectOutput: Bool = false) {
    self.redirectOutput = redirectOutput
    process = Process()
    process.launchPath = launchPath
    process.arguments = arguments
    process.environment = environment.merging(ProcessInfo.processInfo.environment) { (current, _) in current }
  }

  func run(terminationHandler: @escaping (ProcessResult) -> Void) {
    let redirects: (out: Pipe, err: Pipe)? = redirectOutput ? (Pipe(), Pipe()) : nil

    if let redirects = redirects {
      process.standardOutput = redirects.out
      process.standardError = redirects.err
    }

    process.terminationHandler = { process in
      var stdout = "", stderr = ""
      if let redirects = redirects {
          stdout = String(data: redirects.out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
          stderr = String(data: redirects.err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      }
      terminationHandler(ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr))
    }
    process.launch()
  }

  func run() -> ProcessResult {
    let redirects: (out: Pipe, err: Pipe)? = redirectOutput ? (Pipe(), Pipe()) : nil
    if let redirects = redirects {
      process.standardOutput = redirects.out
      process.standardError = redirects.err
    }

    process.launch()
    process.waitUntilExit()

    var stdout = "", stderr = ""
    if let redirects = redirects {
      stdout = String(data: redirects.out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      stderr = String(data: redirects.err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    return ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
  }

  func terminate() {
    process.terminate()
  }
}

/// A queue of subprocesses to be run in parallel
class ProcessQueue {
  typealias PositionedRunner = (offset: Int, element: ProcessRunner)
  typealias PositionedResult = (offset: Int, element: ProcessResult)

  let serialQueue = DispatchQueue(label: "")
  let stopOnFailure: Bool
  let maxWorkers: Int
  let group = DispatchGroup()
  var todo: [PositionedRunner] = []
  var running: [PositionedRunner] = []
  var results = [PositionedResult]()
  var anyFailed = false

  /// Initializes a ProcessQueue containing the provided process runners
  /// - parameters:
  ///   - runners: The subprocesses to be added to the queue in order
  ///   - maxWorkers: The maximum number of subprocesses to run concurrently
  ///   - stopOnFailure: If true, when a subprocess fails, those later in the queue will be terminated (if running) or ignored
  init(_ runners: [ProcessRunner], maxWorkers: Int, stopOnFailure: Bool) {
    self.stopOnFailure = stopOnFailure
    self.maxWorkers = maxWorkers

    let runners = Array(runners.enumerated())
    if maxWorkers < runners.count {
      self.running = Array(runners[..<maxWorkers])
      self.todo = runners[maxWorkers...].reversed()
    } else {
      self.running = runners
    }
  }

  func run() -> (failed: Bool, output: [ProcessResult]) {
    running.forEach(start)
    group.wait()
    var output = results
      .sorted {$0.offset < $1.offset}
      .map {$0.element}
    if stopOnFailure {
      let firstFail = output.firstIndex {$0.status != EXIT_SUCCESS} ?? output.endIndex - 1
      return (anyFailed, Array(output[...firstFail]))
    }
    return (anyFailed, output)
  }
}

private extension ProcessQueue {
  func start(_ runner: PositionedRunner) {
    group.enter()
    runner.element.run() { result in
      self.terminated(runner, result: result)
      self.group.leave()
    }
  }

  func terminated(_ runner: PositionedRunner, result: ProcessResult) {
    serialQueue.sync {
      results.append((offset: runner.offset, element: result))
      let failed = result.status != EXIT_SUCCESS
      let index = running.firstIndex {$0.element === runner.element}!
      if failed && stopOnFailure {
        todo.removeAll()
        running.dropFirst()
          .filter {$0.offset > runner.offset}
          .forEach {$0.element.terminate()}
      }
      running.remove(at: index)
      anyFailed = anyFailed || failed
      if let next = todo.popLast() {
        running.append(next)
        start(next)
      }
    }
  }
}
