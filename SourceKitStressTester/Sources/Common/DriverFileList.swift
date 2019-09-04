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

import Foundation

public struct DriverFileList {
  public let paths: [String]

  public init?(at path: String) {
    guard path.starts(with: "@") else { return nil }
    let url = URL(fileURLWithPath: String(path.dropFirst()), isDirectory: false)
    if let content = try? String(contentsOf: url, encoding: .utf8) {
      paths = content.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    } else {
      return nil
    }
  }
}
