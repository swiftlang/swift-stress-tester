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
public class ProcessRunner {
  private static let serialQueue = DispatchQueue(label: "\(ProcessRunner.self)")

  let process: Process
  var launched = false

  public init(launchPath: String, arguments: [String],
              environment: [String: String] = [:]) {
    process = Process()
    process.launchPath = launchPath
    process.arguments = arguments
    process.environment = environment.merging(ProcessInfo.processInfo.environment) { (current, _) in current }
  }

  public func run(input: String? = nil,
                  captureStdout: Bool = true,
                  captureStderr: Bool = true) -> ProcessResult {
    let group = DispatchGroup()

    if let input = input {
      guard let data = input.data(using: .utf8) else {
        return ProcessResult(status: 1,
                             stdout: Data(),
                             stderr: "Invalid input".data(using: .utf8)!)
      }
      let inPipe = Pipe()
      inPipe.fileHandleForWriting.write(data)
      inPipe.fileHandleForWriting.closeFile()
      process.standardInput = inPipe
    }

    var outData = Data()
    if captureStdout {
      let outPipe = Pipe()
      process.standardOutput = outPipe
      addHandler(pipe: outPipe, group: group) { outData.append($0) }
    }

    var errData = Data()
    if captureStderr {
      let errPipe = Pipe()
      process.standardError = errPipe
      addHandler(pipe: errPipe, group: group) { errData.append($0) }
    }

    ProcessRunner.serialQueue.sync {
      process.launch()
      launched = true
    }

    process.waitUntilExit()
    if captureStdout || captureStderr {
      // Make sure we've received all stdout/stderr
      group.wait()
    }

    return ProcessResult(status: process.terminationStatus,
                         stdout: outData, stderr: errData)
  }

  public func terminate() {
    ProcessRunner.serialQueue.sync {
      if launched {
        process.terminate()
      }
    }
  }

  private func addHandler(pipe: Pipe, group: DispatchGroup,
                          addData: @escaping (Data) -> Void) {
    group.enter()
    pipe.fileHandleForReading.readabilityHandler = { fileHandle in
      // Apparently using availableData can cause various issues
      let newData = fileHandle.readData(ofLength: Int.max)
      if newData.count == 0 {
        pipe.fileHandleForReading.readabilityHandler = nil;
        group.leave()
      } else {
        addData(newData)
      }
    }
  }
}

/// The exit code and output (if redirected) from a subprocess that has
/// terminated
public struct ProcessResult {
  public let status: Int32
  public let stdout: Data
  public let stderr: Data

  public var stdoutStr: String? {
    return String(data: stdout, encoding: .utf8)
  }
  public var stderrStr: String? {
    return String(data: stderr, encoding: .utf8)
  }
}

public func pathFromXcrun(for tool: String, in toolchain: String? = nil) -> String? {
  var args = ["-f", tool]
  if let toolchain = toolchain {
    args += ["--toolchain", toolchain]
  }
  let result = ProcessRunner(launchPath: "/usr/bin/xcrun", arguments: args).run()
  guard result.status == EXIT_SUCCESS else { return nil }

  return result.stdoutStr?.trimmingCharacters(in: .whitespacesAndNewlines)
}
