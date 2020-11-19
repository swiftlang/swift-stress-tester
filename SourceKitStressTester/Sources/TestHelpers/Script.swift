//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

public struct ExecutableScript {
  public let file: URL
  let invocationFile: URL?

  @discardableResult
  public init(at file: URL, exitCode: Int32, stdout: String? = nil,
              stderr: String? = nil,
              recordInvocationIn invocationFile: URL? = nil) {
    self.file = file
    self.invocationFile = invocationFile

    var lines = ["#!/usr/bin/env bash"]
    if let stdout = stdout {
      lines.append("echo '\(stdout)'")
    }
    if let stderr = stderr {
      lines.append("echo '\(stderr)' >&2")
    }
    if let invocationFile = invocationFile {
      lines.append("echo $@ >> \(invocationFile.path)")
    }
    lines.append("exit \(exitCode)")

    let content = lines.joined(separator: "\n").data(using: .utf8)
    FileManager.default.createFile(
      atPath: file.path, contents: content,
      attributes: [FileAttributeKey.posixPermissions: 0o0755])
  }

  public func retrieveInvocations() -> [Substring] {
    return (try? String(contentsOf: invocationFile!).split(separator: "\n")) ?? []
  }
}
