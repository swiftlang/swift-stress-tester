// SwiftEvolve/Log.swift - Logging to stderr
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
// -----------------------------------------------------------------------------
///
/// This file implements a log() function which can be used to write to stderr.
///
// -----------------------------------------------------------------------------

import Foundation

func log(_ items: Any..., separator: String = " ", terminator: String = "\n") {
  var stderr = FileHandle.standardError
  print(items.map(String.init(describing:)).joined(separator: separator),
        terminator: terminator, to: &stderr)
}

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    self.write(string.data(using: .utf8)!)
  }
}
