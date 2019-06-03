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

extension String {
  public var stableHash: UInt64 {
    var hash: UInt64 = 5381
    for byte in utf8 {
      hash = 127 * (hash & 0x00ffffffffffffff) + UInt64(byte)
    }
    return hash
  }
}
